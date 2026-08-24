## Numeric interpretations as prelude brands over bitsN (D24/D25). Floating point
## (f32/f64); uN/iN are compiler-provided (a width-parameterized family).
f32 := brand(bits32)
f64 := brand(bits64)

## Floating-point arithmetic operators (§4 / D61) — library functions naming the
## scalar-FP intrinsic (x86_64 `addsd`/`subsd`/`mulsd`/`divsd` for `f64`,
## `addss`/… for `f32`). A float is held as its IEEE-754 bit pattern in a GP
## register; the intrinsic lowering bounces it through `xmm` (the same dance the
## built-in `float_binop` did). **No overflow guard** — IEEE arithmetic is total
## (overflow → ±inf, `0/0` → NaN), never a trap (D61). One-instruction bodies, so
## inlined (I2). x86_64-gated like the integer scalar operators.
@inline + := fn(a : f64, b : f64) -> f64 {
  mut out : f64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.addsd(out, b) }
  return out
}
@inline - := fn(a : f64, b : f64) -> f64 {
  mut out : f64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.subsd(out, b) }
  return out
}
@inline * := fn(a : f64, b : f64) -> f64 {
  mut out : f64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.mulsd(out, b) }
  return out
}
@inline / := fn(a : f64, b : f64) -> f64 {
  mut out : f64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.divsd(out, b) }
  return out
}
@inline + := fn(a : f32, b : f32) -> f32 {
  mut out : f32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.addss(out, b) }
  return out
}
@inline - := fn(a : f32, b : f32) -> f32 {
  mut out : f32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.subss(out, b) }
  return out
}
@inline * := fn(a : f32, b : f32) -> f32 {
  mut out : f32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.mulss(out, b) }
  return out
}
@inline / := fn(a : f32, b : f32) -> f32 {
  mut out : f32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.divss(out, b) }
  return out
}

## Native integer operators as library functions (D24/D25.3 — signedness IS the
## instruction the body names; the implementation differs per target via
## `comptime if target.arch`). The override-desugar routes `a <op> b` over u64/i64
## to these (overload-mangled per type), each inlining to the bare instruction.
##
## The instruction is **arch-qualified** (`x86_64.divq`, `aarch64.sdiv`, §80/D25.3):
## a qualified mnemonic cannot be shadowed by a user function, so a body may name
## `div` — a mnemonic that collides with a common function name — without
## ambiguity. x86_64 uses the implicit-`rdx:rax` 1-operand divides (`divq`/`idivq`);
## aarch64 / riscv64 use the 3-operand `Rd, Rn, Rm` forms (`udiv`/`sdiv`,
## `divu`/`div`). Checked arithmetic and div-by-zero guards belong to the operation site
## (CG-13), not to this implementation body; the body is raw and mode-independent.
##
## **Every integer scalar operator is now a library function on x86_64** — all
## five arithmetic (`+`/`-`/`*`/`/`/`%`) and the six comparisons (`cmp.al`),
## for `u8`/`i8`/`u16`/`i16`/`u32`/`i32`/`u64`/`i64` (and `usize`/`isize` as D23
## aliases of the pointer-width integer). Scalar-operator routing is **x86_64-
## gated** (`routes_comparison`), so other arches keep the built-in lowering until
## their operator support lands. The 64-bit ops name the bare instruction
## directly; the 32/16/8-bit ops **widen to 64 bits**, apply the existing 64-bit
## intrinsic, range-check the narrow result, and truncate (so they reuse the
## 64-bit divmod/high-multiply shapes — no narrower-width divmod intrinsic needed,
## and the inlinable body stays zero-cost, I2). **`f32`/`f64` `+`/`-`/`*`/`/` are
## library too** (defined at the top of this file, naming the SSE intrinsics via
## the `scalar_fp_width` GP↔xmm dance; IEEE-total, no guard). So **every scalar
## operator is a library function on x86_64**. (Float **comparisons** remain
## built-in — the NaN-unordered `ucomisd`+parity shape — a follow-up.)

@inline / := fn(a : u64, b : u64) -> u64 {
  mut out : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.divq(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.udiv(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.divu(out, a, b) }
  return out
}

@inline / := fn(a : i64, b : i64) -> i64 {
  mut out : i64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.idivq(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.sdiv(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.div(out, a, b) }
  return out
}

## Addition / subtraction — same shape (x86_64 destination-first `addq`/`subq`;
## aarch64 / riscv64 3-operand `add`/`sub`). Checked overflow belongs to the
## operation site; these routed bodies contain only the raw instruction.
@inline + := fn(a : u64, b : u64) -> u64 {
  mut out : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.addq(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.add(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.add(out, a, b) }
  return out
}

@inline + := fn(a : i64, b : i64) -> i64 {
  mut out : i64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.addq(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.add(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.add(out, a, b) }
  return out
}

@inline - := fn(a : u64, b : u64) -> u64 {
  mut out : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.subq(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.sub(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.sub(out, a, b) }
  return out
}

@inline - := fn(a : i64, b : i64) -> i64 {
  mut out : i64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.subq(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.sub(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.sub(out, a, b) }
  return out
}

## 32-bit `+`/`-` for `u32`/`i32` — the narrower-width counterpart of the 64-bit
## operators (D24/D25.3). Same shape, at 32-bit width on **every** arch (a 32-bit
## target's `usize`/`isize` IS `u32`/`i32`, D23, so these must cover all arches):
## the x86 family uses the 2-operand `addl`/`subl` (on x86_64 the lowering spells
## the operands at the 32-bit sub-register; on i386 the registers are already
## 32-bit), riscv the `addw`/`subw` (64-bit) or native `add`/`sub` (riscv32),
## aarch the width-agnostic `add`/`sub`. The operation-site guard uses the same comparison
## logic at 32-bit width (`u32`/`i32` comparisons). (`*`/`/`/`%` for narrower
## widths need a 32-bit divmod/high-multiply shape — a follow-up; they stay
## compiler-lowered for now.)
@inline + := fn(a : u32, b : u32) -> u32 {
  mut out : u32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.addl(out, b) }
  comptime if target.arch == Arch.i386 { i386.addl(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.add(out, a, b) }
  comptime if target.arch == Arch.aarch32 { aarch32.add(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.addw(out, a, b) }
  comptime if target.arch == Arch.riscv32 { riscv32.add(out, a, b) }
  return out
}

@inline + := fn(a : i32, b : i32) -> i32 {
  mut out : i32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.addl(out, b) }
  comptime if target.arch == Arch.i386 { i386.addl(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.add(out, a, b) }
  comptime if target.arch == Arch.aarch32 { aarch32.add(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.addw(out, a, b) }
  comptime if target.arch == Arch.riscv32 { riscv32.add(out, a, b) }
  return out
}

@inline - := fn(a : u32, b : u32) -> u32 {
  mut out : u32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.subl(out, b) }
  comptime if target.arch == Arch.i386 { i386.subl(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.sub(out, a, b) }
  comptime if target.arch == Arch.aarch32 { aarch32.sub(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.subw(out, a, b) }
  comptime if target.arch == Arch.riscv32 { riscv32.sub(out, a, b) }
  return out
}

@inline - := fn(a : i32, b : i32) -> i32 {
  mut out : i32 = a
  comptime if target.arch == Arch.x86_64 { x86_64.subl(out, b) }
  comptime if target.arch == Arch.i386 { i386.subl(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.sub(out, a, b) }
  comptime if target.arch == Arch.aarch32 { aarch32.sub(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.subw(out, a, b) }
  comptime if target.arch == Arch.riscv32 { riscv32.sub(out, a, b) }
  return out
}

## Multiplication — the low 64-bit product is the two-operand `imulq` (x86_64) /
## 3-operand `mul` (aarch64/riscv64), identical for signed and unsigned. The
## operation-site guard reads the **high** 64 bits of the full product (a light flag-free
## comparison, no division): unsigned overflows iff the high half is non-zero;
## signed overflows iff the high half is not the sign-extension of the low (`0` for
## a non-negative product, all-ones `-1` for a negative one). High-half intrinsics:
## x86_64 synthetic `mulhiq`/`imulhiq` (1-operand `mulq`/`imulq`, capture `rdx`),
## aarch64 `umulh`/`smulh`, riscv64 `mulhu`/`mulh`.
@inline * := fn(a : u64, b : u64) -> u64 {
  mut out : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.imulq(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.mul(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.mul(out, a, b) }
  return out
}

@inline * := fn(a : i64, b : i64) -> i64 {
  mut out : i64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.imulq(out, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.mul(out, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.mul(out, a, b) }
  return out
}

## Remainder — the `rdx` half of the same divide (signedness IS the instruction).
## x86_64: the synthetic `remq`/`iremq` emit `divq`/`idivq` and capture `rdx`;
## riscv64: `remu`/`rem` (3-operand); aarch64 has no remainder op — compute it as
## `a - (a / b) * b` via `udiv`/`sdiv` + `msub` (Rd = Ra - Rn*Rm). Only an operation-site
## div-by-zero guard is needed (a remainder cannot overflow), like `/`, so the guard is light.
@inline % := fn(a : u64, b : u64) -> u64 {
  mut out : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.remq(out, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.remu(out, a, b) }
  comptime if target.arch == Arch.aarch64 {
    mut q : u64 = a
    aarch64.udiv(q, a, b)
    aarch64.msub(out, q, b, a)
  }
  return out
}

@inline % := fn(a : i64, b : i64) -> i64 {
  mut out : i64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.iremq(out, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.rem(out, a, b) }
  comptime if target.arch == Arch.aarch64 {
    mut q : i64 = a
    aarch64.sdiv(q, a, b)
    aarch64.msub(out, q, b, a)
  }
  return out
}

## 32-bit `*`/`/`/`%` for `u32`/`i32` (§4). Scalar-arithmetic routing is x86_64-
## gated (like comparisons), so these are only ever selected on x86_64. They reuse
## the existing **64-bit** instruction intrinsics on the **widened** operands —
## naming an intrinsic keeps the body inlinable (zero-cost, I2). A 32-bit value
## widened to 64 bits makes a 32×32 product / 32÷32 divide impossible to overflow
## at 64-bit, so the 64-bit op is exact; the operation-site checked guards are the precise
## `u32`/`i32` overflow conditions, then the result truncates back (wrapping under
## `unchecked`). (On a 32-bit target `u64` is multi-word; these stay
## compiler-lowered there, reached via the built-in path, not this fn.)
@inline * := fn(a : u32, b : u32) -> u32 {
  mut full := u64(a)
  wb := u64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.imulq(full, wb) }
  return unchecked { u32(full) }
}

@inline * := fn(a : i32, b : i32) -> i32 {
  mut full := i64(a)
  wb := i64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.imulq(full, wb) }
  return unchecked { i32(full) }
}

@inline / := fn(a : u32, b : u32) -> u32 {
  mut full := u64(a)
  wb := u64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.divq(full, wb) }
  return unchecked { u32(full) }
}

@inline / := fn(a : i32, b : i32) -> i32 {
  mut full := i64(a)
  wb := i64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.idivq(full, wb) }
  return unchecked { i32(full) }
}

@inline % := fn(a : u32, b : u32) -> u32 {
  mut full := u64(a)
  wb := u64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.remq(full, wb) }
  return unchecked { u32(full) }
}

@inline % := fn(a : i32, b : i32) -> i32 {
  mut full := i64(a)
  wb := i64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.iremq(full, wb) }
  return unchecked { i32(full) }
}

## 8-bit / 16-bit integer operators (§4) — the same x86_64-gated, 64-bit-widening
## scheme as `u32`/`i32`: widen to 64 bits, apply the 64-bit intrinsic, range-check
## the narrow result, truncate. Bounds: `u8` [0,255], `u16` [0,65535], `i8`
## [-128,127], `i16` [-32768,32767]. Only the x86_64 branch is needed (the gate).
@inline + := fn(a : u8, b : u8) -> u8 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.addq(full, u64(b)) }
  return unchecked { u8(full) }
}
@inline - := fn(a : u8, b : u8) -> u8 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.subq(full, u64(b)) }
  return unchecked { u8(full) }
}
@inline * := fn(a : u8, b : u8) -> u8 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.imulq(full, u64(b)) }
  return unchecked { u8(full) }
}
@inline / := fn(a : u8, b : u8) -> u8 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.divq(full, u64(b)) }
  return unchecked { u8(full) }
}
@inline % := fn(a : u8, b : u8) -> u8 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.remq(full, u64(b)) }
  return unchecked { u8(full) }
}

@inline + := fn(a : u16, b : u16) -> u16 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.addq(full, u64(b)) }
  return unchecked { u16(full) }
}
@inline - := fn(a : u16, b : u16) -> u16 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.subq(full, u64(b)) }
  return unchecked { u16(full) }
}
@inline * := fn(a : u16, b : u16) -> u16 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.imulq(full, u64(b)) }
  return unchecked { u16(full) }
}
@inline / := fn(a : u16, b : u16) -> u16 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.divq(full, u64(b)) }
  return unchecked { u16(full) }
}
@inline % := fn(a : u16, b : u16) -> u16 {
  mut full := u64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.remq(full, u64(b)) }
  return unchecked { u16(full) }
}

@inline + := fn(a : i8, b : i8) -> i8 {
  mut full := i64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.addq(full, i64(b)) }
  return unchecked { i8(full) }
}
@inline - := fn(a : i8, b : i8) -> i8 {
  mut full := i64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.subq(full, i64(b)) }
  return unchecked { i8(full) }
}
@inline * := fn(a : i8, b : i8) -> i8 {
  mut full := i64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.imulq(full, i64(b)) }
  return unchecked { i8(full) }
}
@inline / := fn(a : i8, b : i8) -> i8 {
  mut full := i64(a)
  wb := i64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.idivq(full, wb) }
  return unchecked { i8(full) }
}
@inline % := fn(a : i8, b : i8) -> i8 {
  mut full := i64(a)
  wb := i64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.iremq(full, wb) }
  return unchecked { i8(full) }
}

@inline + := fn(a : i16, b : i16) -> i16 {
  mut full := i64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.addq(full, i64(b)) }
  return unchecked { i16(full) }
}
@inline - := fn(a : i16, b : i16) -> i16 {
  mut full := i64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.subq(full, i64(b)) }
  return unchecked { i16(full) }
}
@inline * := fn(a : i16, b : i16) -> i16 {
  mut full := i64(a)
  comptime if target.arch == Arch.x86_64 { x86_64.imulq(full, i64(b)) }
  return unchecked { i16(full) }
}
@inline / := fn(a : i16, b : i16) -> i16 {
  mut full := i64(a)
  wb := i64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.idivq(full, wb) }
  return unchecked { i16(full) }
}
@inline % := fn(a : i16, b : i16) -> i16 {
  mut full := i64(a)
  wb := i64(b)
  comptime if target.arch == Arch.x86_64 { x86_64.iremq(full, wb) }
  return unchecked { i16(full) }
}

## ===========================================================================
## Explicit overflow-policy operations (Concurrency §6.3 / CG-8; appendix 160 §4.3).
## Available EVERYWHERE (no `unchecked` grant) as ordinary prelude functions —
## resolved by UFCS, so both `wrapping_add(a, b)` and `a.wrapping_add(b)` work
## (Type System §4.5). Four families per operation, on the integer interpretations
## `uN`/`iN` (`usize`/`isize` are D23 aliases of the pointer-width integer, covered
## by the `u64`/`i64` overloads on x86_64):
##   wrapping_*    -> T           (two's-complement wrap; == an `unchecked` op)
##   saturating_*  -> T           (clamp to the type's [min, max])
##   checked_*     -> Option(T)   (None on overflow, else Some(wrapped))
##   overflowing_* -> (T, bool)   (the wrapped value and an overflow flag)
## Operations: `add` / `sub` / `mul` (the binary members of the checked-overflow
## set `+ - * unary- MIN/-1`; unary `neg` and `div`'s MIN/-1 case are a follow-on).
##
## Mechanism (no new codegen — a NEUTRAL library addition, dormant for the self
## build): the wrapped result is `unchecked { a <op> b }` (unchecked arithmetic
## wraps at the hardware width, §6.2). Overflow is DETECTED in-language: unsigned
## add overflows iff the wrapped sum `< a`; unsigned sub (underflow) iff `a < b`;
## signed by sign comparison; multiplication for the sub-64 widths by a 64-bit
## widening (the exact product cannot overflow 64 bits, then range-check), and for
## the 64-bit widths by the high-half-of-product intrinsic (the same light,
## division-free check `num.al`'s checked `*` uses). Locals are TYPE-ANNOTATED
## (never `x := unchecked { … }`): an inferred binding off an `unchecked` block
## mis-delivers the second tuple word out of these functions (a seed limitation).
## x86_64-first, like the scalar operators above (the `mulhi` branch mirrors the
## other arches for parity; the routing is x86_64-gated).

## ---- u8 ----
wrapping_add := fn(a : u8, b : u8) -> u8 { return unchecked { a + b } }
wrapping_sub := fn(a : u8, b : u8) -> u8 { return unchecked { a - b } }
wrapping_mul := fn(a : u8, b : u8) -> u8 { return unchecked { a * b } }
overflowing_add := fn(a : u8, b : u8) -> (u8, bool) {
  w : u8 = unchecked { a + b }
  o : bool = w < a
  return (w, o)
}
overflowing_sub := fn(a : u8, b : u8) -> (u8, bool) {
  w : u8 = unchecked { a - b }
  o : bool = a < b
  return (w, o)
}
overflowing_mul := fn(a : u8, b : u8) -> (u8, bool) {
  full : u64 = unchecked { u64(a) * u64(b) }
  o : bool = full > 255
  w : u8 = unchecked { u8(full) }
  return (w, o)
}
checked_add := fn(a : u8, b : u8) -> Option(u8) {
  w : u8 = unchecked { a + b }
  if w < a { return Option(u8).None }
  return Option(u8).Some(w)
}
checked_sub := fn(a : u8, b : u8) -> Option(u8) {
  if a < b { return Option(u8).None }
  w : u8 = unchecked { a - b }
  return Option(u8).Some(w)
}
checked_mul := fn(a : u8, b : u8) -> Option(u8) {
  full : u64 = unchecked { u64(a) * u64(b) }
  if full > 255 { return Option(u8).None }
  w : u8 = unchecked { u8(full) }
  return Option(u8).Some(w)
}
saturating_add := fn(a : u8, b : u8) -> u8 {
  w : u8 = unchecked { a + b }
  if w < a { return 255 }
  return w
}
saturating_sub := fn(a : u8, b : u8) -> u8 {
  if a < b { return 0 }
  return unchecked { a - b }
}
saturating_mul := fn(a : u8, b : u8) -> u8 {
  full : u64 = unchecked { u64(a) * u64(b) }
  if full > 255 { return 255 }
  w : u8 = unchecked { u8(full) }
  return w
}

## ---- u16 ----
wrapping_add := fn(a : u16, b : u16) -> u16 { return unchecked { a + b } }
wrapping_sub := fn(a : u16, b : u16) -> u16 { return unchecked { a - b } }
wrapping_mul := fn(a : u16, b : u16) -> u16 { return unchecked { a * b } }
overflowing_add := fn(a : u16, b : u16) -> (u16, bool) {
  w : u16 = unchecked { a + b }
  o : bool = w < a
  return (w, o)
}
overflowing_sub := fn(a : u16, b : u16) -> (u16, bool) {
  w : u16 = unchecked { a - b }
  o : bool = a < b
  return (w, o)
}
overflowing_mul := fn(a : u16, b : u16) -> (u16, bool) {
  full : u64 = unchecked { u64(a) * u64(b) }
  o : bool = full > 65535
  w : u16 = unchecked { u16(full) }
  return (w, o)
}
checked_add := fn(a : u16, b : u16) -> Option(u16) {
  w : u16 = unchecked { a + b }
  if w < a { return Option(u16).None }
  return Option(u16).Some(w)
}
checked_sub := fn(a : u16, b : u16) -> Option(u16) {
  if a < b { return Option(u16).None }
  w : u16 = unchecked { a - b }
  return Option(u16).Some(w)
}
checked_mul := fn(a : u16, b : u16) -> Option(u16) {
  full : u64 = unchecked { u64(a) * u64(b) }
  if full > 65535 { return Option(u16).None }
  w : u16 = unchecked { u16(full) }
  return Option(u16).Some(w)
}
saturating_add := fn(a : u16, b : u16) -> u16 {
  w : u16 = unchecked { a + b }
  if w < a { return 65535 }
  return w
}
saturating_sub := fn(a : u16, b : u16) -> u16 {
  if a < b { return 0 }
  return unchecked { a - b }
}
saturating_mul := fn(a : u16, b : u16) -> u16 {
  full : u64 = unchecked { u64(a) * u64(b) }
  if full > 65535 { return 65535 }
  w : u16 = unchecked { u16(full) }
  return w
}

## ---- u32 ----
wrapping_add := fn(a : u32, b : u32) -> u32 { return unchecked { a + b } }
wrapping_sub := fn(a : u32, b : u32) -> u32 { return unchecked { a - b } }
wrapping_mul := fn(a : u32, b : u32) -> u32 { return unchecked { a * b } }
overflowing_add := fn(a : u32, b : u32) -> (u32, bool) {
  w : u32 = unchecked { a + b }
  o : bool = w < a
  return (w, o)
}
overflowing_sub := fn(a : u32, b : u32) -> (u32, bool) {
  w : u32 = unchecked { a - b }
  o : bool = a < b
  return (w, o)
}
overflowing_mul := fn(a : u32, b : u32) -> (u32, bool) {
  full : u64 = unchecked { u64(a) * u64(b) }
  o : bool = full > 4294967295
  w : u32 = unchecked { u32(full) }
  return (w, o)
}
checked_add := fn(a : u32, b : u32) -> Option(u32) {
  w : u32 = unchecked { a + b }
  if w < a { return Option(u32).None }
  return Option(u32).Some(w)
}
checked_sub := fn(a : u32, b : u32) -> Option(u32) {
  if a < b { return Option(u32).None }
  w : u32 = unchecked { a - b }
  return Option(u32).Some(w)
}
checked_mul := fn(a : u32, b : u32) -> Option(u32) {
  full : u64 = unchecked { u64(a) * u64(b) }
  if full > 4294967295 { return Option(u32).None }
  w : u32 = unchecked { u32(full) }
  return Option(u32).Some(w)
}
saturating_add := fn(a : u32, b : u32) -> u32 {
  w : u32 = unchecked { a + b }
  if w < a { return 4294967295 }
  return w
}
saturating_sub := fn(a : u32, b : u32) -> u32 {
  if a < b { return 0 }
  return unchecked { a - b }
}
saturating_mul := fn(a : u32, b : u32) -> u32 {
  full : u64 = unchecked { u64(a) * u64(b) }
  if full > 4294967295 { return 4294967295 }
  w : u32 = unchecked { u32(full) }
  return w
}

## ---- u64 ---- (mul overflow via the high-half-of-product intrinsic)
wrapping_add := fn(a : u64, b : u64) -> u64 { return unchecked { a + b } }
wrapping_sub := fn(a : u64, b : u64) -> u64 { return unchecked { a - b } }
wrapping_mul := fn(a : u64, b : u64) -> u64 { return unchecked { a * b } }
overflowing_add := fn(a : u64, b : u64) -> (u64, bool) {
  w : u64 = unchecked { a + b }
  o : bool = w < a
  return (w, o)
}
overflowing_sub := fn(a : u64, b : u64) -> (u64, bool) {
  w : u64 = unchecked { a - b }
  o : bool = a < b
  return (w, o)
}
overflowing_mul := fn(a : u64, b : u64) -> (u64, bool) {
  w : u64 = unchecked { a * b }
  mut hi : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.mulhiq(hi, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.umulh(hi, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.mulhu(hi, a, b) }
  o : bool = hi != 0
  return (w, o)
}
checked_add := fn(a : u64, b : u64) -> Option(u64) {
  w : u64 = unchecked { a + b }
  if w < a { return Option(u64).None }
  return Option(u64).Some(w)
}
checked_sub := fn(a : u64, b : u64) -> Option(u64) {
  if a < b { return Option(u64).None }
  w : u64 = unchecked { a - b }
  return Option(u64).Some(w)
}
checked_mul := fn(a : u64, b : u64) -> Option(u64) {
  w : u64 = unchecked { a * b }
  mut hi : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.mulhiq(hi, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.umulh(hi, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.mulhu(hi, a, b) }
  if hi != 0 { return Option(u64).None }
  return Option(u64).Some(w)
}
saturating_add := fn(a : u64, b : u64) -> u64 {
  w : u64 = unchecked { a + b }
  if w < a { return 18446744073709551615 }
  return w
}
saturating_sub := fn(a : u64, b : u64) -> u64 {
  if a < b { return 0 }
  return unchecked { a - b }
}
saturating_mul := fn(a : u64, b : u64) -> u64 {
  w : u64 = unchecked { a * b }
  mut hi : u64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.mulhiq(hi, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.umulh(hi, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.mulhu(hi, a, b) }
  if hi != 0 { return 18446744073709551615 }
  return w
}

## ---- i8 ----
wrapping_add := fn(a : i8, b : i8) -> i8 { return unchecked { a + b } }
wrapping_sub := fn(a : i8, b : i8) -> i8 { return unchecked { a - b } }
wrapping_mul := fn(a : i8, b : i8) -> i8 { return unchecked { a * b } }
overflowing_add := fn(a : i8, b : i8) -> (i8, bool) {
  w : i8 = unchecked { a + b }
  mut o : bool = false
  if b >= 0 and w < a { o = true }
  if b < 0 and w > a { o = true }
  return (w, o)
}
overflowing_sub := fn(a : i8, b : i8) -> (i8, bool) {
  w : i8 = unchecked { a - b }
  mut o : bool = false
  if b > 0 and w > a { o = true }
  if b < 0 and w < a { o = true }
  return (w, o)
}
overflowing_mul := fn(a : i8, b : i8) -> (i8, bool) {
  full : i64 = unchecked { i64(a) * i64(b) }
  mut o : bool = false
  if full > 127 { o = true }
  if full < (0 - 128) { o = true }
  w : i8 = unchecked { i8(full) }
  return (w, o)
}
checked_add := fn(a : i8, b : i8) -> Option(i8) {
  w : i8 = unchecked { a + b }
  if b >= 0 and w < a { return Option(i8).None }
  if b < 0 and w > a { return Option(i8).None }
  return Option(i8).Some(w)
}
checked_sub := fn(a : i8, b : i8) -> Option(i8) {
  w : i8 = unchecked { a - b }
  if b > 0 and w > a { return Option(i8).None }
  if b < 0 and w < a { return Option(i8).None }
  return Option(i8).Some(w)
}
checked_mul := fn(a : i8, b : i8) -> Option(i8) {
  full : i64 = unchecked { i64(a) * i64(b) }
  if full > 127 { return Option(i8).None }
  if full < (0 - 128) { return Option(i8).None }
  w : i8 = unchecked { i8(full) }
  return Option(i8).Some(w)
}
saturating_add := fn(a : i8, b : i8) -> i8 {
  w : i8 = unchecked { a + b }
  if b >= 0 and w < a { return 127 }
  if b < 0 and w > a { return i8(0 - 128) }
  return w
}
saturating_sub := fn(a : i8, b : i8) -> i8 {
  w : i8 = unchecked { a - b }
  if b < 0 and w < a { return 127 }
  if b > 0 and w > a { return i8(0 - 128) }
  return w
}
saturating_mul := fn(a : i8, b : i8) -> i8 {
  full : i64 = unchecked { i64(a) * i64(b) }
  if full > 127 { return 127 }
  if full < (0 - 128) { return i8(0 - 128) }
  w : i8 = unchecked { i8(full) }
  return w
}

## ---- i16 ----
wrapping_add := fn(a : i16, b : i16) -> i16 { return unchecked { a + b } }
wrapping_sub := fn(a : i16, b : i16) -> i16 { return unchecked { a - b } }
wrapping_mul := fn(a : i16, b : i16) -> i16 { return unchecked { a * b } }
overflowing_add := fn(a : i16, b : i16) -> (i16, bool) {
  w : i16 = unchecked { a + b }
  mut o : bool = false
  if b >= 0 and w < a { o = true }
  if b < 0 and w > a { o = true }
  return (w, o)
}
overflowing_sub := fn(a : i16, b : i16) -> (i16, bool) {
  w : i16 = unchecked { a - b }
  mut o : bool = false
  if b > 0 and w > a { o = true }
  if b < 0 and w < a { o = true }
  return (w, o)
}
overflowing_mul := fn(a : i16, b : i16) -> (i16, bool) {
  full : i64 = unchecked { i64(a) * i64(b) }
  mut o : bool = false
  if full > 32767 { o = true }
  if full < (0 - 32768) { o = true }
  w : i16 = unchecked { i16(full) }
  return (w, o)
}
checked_add := fn(a : i16, b : i16) -> Option(i16) {
  w : i16 = unchecked { a + b }
  if b >= 0 and w < a { return Option(i16).None }
  if b < 0 and w > a { return Option(i16).None }
  return Option(i16).Some(w)
}
checked_sub := fn(a : i16, b : i16) -> Option(i16) {
  w : i16 = unchecked { a - b }
  if b > 0 and w > a { return Option(i16).None }
  if b < 0 and w < a { return Option(i16).None }
  return Option(i16).Some(w)
}
checked_mul := fn(a : i16, b : i16) -> Option(i16) {
  full : i64 = unchecked { i64(a) * i64(b) }
  if full > 32767 { return Option(i16).None }
  if full < (0 - 32768) { return Option(i16).None }
  w : i16 = unchecked { i16(full) }
  return Option(i16).Some(w)
}
saturating_add := fn(a : i16, b : i16) -> i16 {
  w : i16 = unchecked { a + b }
  if b >= 0 and w < a { return 32767 }
  if b < 0 and w > a { return i16(0 - 32768) }
  return w
}
saturating_sub := fn(a : i16, b : i16) -> i16 {
  w : i16 = unchecked { a - b }
  if b < 0 and w < a { return 32767 }
  if b > 0 and w > a { return i16(0 - 32768) }
  return w
}
saturating_mul := fn(a : i16, b : i16) -> i16 {
  full : i64 = unchecked { i64(a) * i64(b) }
  if full > 32767 { return 32767 }
  if full < (0 - 32768) { return i16(0 - 32768) }
  w : i16 = unchecked { i16(full) }
  return w
}

## ---- i32 ----
wrapping_add := fn(a : i32, b : i32) -> i32 { return unchecked { a + b } }
wrapping_sub := fn(a : i32, b : i32) -> i32 { return unchecked { a - b } }
wrapping_mul := fn(a : i32, b : i32) -> i32 { return unchecked { a * b } }
overflowing_add := fn(a : i32, b : i32) -> (i32, bool) {
  w : i32 = unchecked { a + b }
  mut o : bool = false
  if b >= 0 and w < a { o = true }
  if b < 0 and w > a { o = true }
  return (w, o)
}
overflowing_sub := fn(a : i32, b : i32) -> (i32, bool) {
  w : i32 = unchecked { a - b }
  mut o : bool = false
  if b > 0 and w > a { o = true }
  if b < 0 and w < a { o = true }
  return (w, o)
}
overflowing_mul := fn(a : i32, b : i32) -> (i32, bool) {
  full : i64 = unchecked { i64(a) * i64(b) }
  mut o : bool = false
  if full > 2147483647 { o = true }
  if full < (0 - 2147483648) { o = true }
  w : i32 = unchecked { i32(full) }
  return (w, o)
}
checked_add := fn(a : i32, b : i32) -> Option(i32) {
  w : i32 = unchecked { a + b }
  if b >= 0 and w < a { return Option(i32).None }
  if b < 0 and w > a { return Option(i32).None }
  return Option(i32).Some(w)
}
checked_sub := fn(a : i32, b : i32) -> Option(i32) {
  w : i32 = unchecked { a - b }
  if b > 0 and w > a { return Option(i32).None }
  if b < 0 and w < a { return Option(i32).None }
  return Option(i32).Some(w)
}
checked_mul := fn(a : i32, b : i32) -> Option(i32) {
  full : i64 = unchecked { i64(a) * i64(b) }
  if full > 2147483647 { return Option(i32).None }
  if full < (0 - 2147483648) { return Option(i32).None }
  w : i32 = unchecked { i32(full) }
  return Option(i32).Some(w)
}
saturating_add := fn(a : i32, b : i32) -> i32 {
  w : i32 = unchecked { a + b }
  if b >= 0 and w < a { return 2147483647 }
  if b < 0 and w > a { return i32(0 - 2147483648) }
  return w
}
saturating_sub := fn(a : i32, b : i32) -> i32 {
  w : i32 = unchecked { a - b }
  if b < 0 and w < a { return 2147483647 }
  if b > 0 and w > a { return i32(0 - 2147483648) }
  return w
}
saturating_mul := fn(a : i32, b : i32) -> i32 {
  full : i64 = unchecked { i64(a) * i64(b) }
  if full > 2147483647 { return 2147483647 }
  if full < (0 - 2147483648) { return i32(0 - 2147483648) }
  w : i32 = unchecked { i32(full) }
  return w
}

## ---- i64 ---- (mul overflow via the signed high-half-of-product intrinsic)
wrapping_add := fn(a : i64, b : i64) -> i64 { return unchecked { a + b } }
wrapping_sub := fn(a : i64, b : i64) -> i64 { return unchecked { a - b } }
wrapping_mul := fn(a : i64, b : i64) -> i64 { return unchecked { a * b } }
overflowing_add := fn(a : i64, b : i64) -> (i64, bool) {
  w : i64 = unchecked { a + b }
  mut o : bool = false
  if b >= 0 and w < a { o = true }
  if b < 0 and w > a { o = true }
  return (w, o)
}
overflowing_sub := fn(a : i64, b : i64) -> (i64, bool) {
  w : i64 = unchecked { a - b }
  mut o : bool = false
  if b > 0 and w > a { o = true }
  if b < 0 and w < a { o = true }
  return (w, o)
}
overflowing_mul := fn(a : i64, b : i64) -> (i64, bool) {
  w : i64 = unchecked { a * b }
  mut hi : i64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.imulhiq(hi, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.smulh(hi, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.mulh(hi, a, b) }
  mut o : bool = false
  if w >= 0 and hi != 0 { o = true }
  if w < 0 and hi != (0 - 1) { o = true }
  return (w, o)
}
checked_add := fn(a : i64, b : i64) -> Option(i64) {
  w : i64 = unchecked { a + b }
  if b >= 0 and w < a { return Option(i64).None }
  if b < 0 and w > a { return Option(i64).None }
  return Option(i64).Some(w)
}
checked_sub := fn(a : i64, b : i64) -> Option(i64) {
  w : i64 = unchecked { a - b }
  if b > 0 and w > a { return Option(i64).None }
  if b < 0 and w < a { return Option(i64).None }
  return Option(i64).Some(w)
}
checked_mul := fn(a : i64, b : i64) -> Option(i64) {
  w : i64 = unchecked { a * b }
  mut hi : i64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.imulhiq(hi, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.smulh(hi, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.mulh(hi, a, b) }
  if w >= 0 and hi != 0 { return Option(i64).None }
  if w < 0 and hi != (0 - 1) { return Option(i64).None }
  return Option(i64).Some(w)
}
saturating_add := fn(a : i64, b : i64) -> i64 {
  w : i64 = unchecked { a + b }
  if b >= 0 and w < a { return 9223372036854775807 }
  if b < 0 and w > a { return (0 - 9223372036854775807 - 1) }
  return w
}
saturating_sub := fn(a : i64, b : i64) -> i64 {
  w : i64 = unchecked { a - b }
  if b < 0 and w < a { return 9223372036854775807 }
  if b > 0 and w > a { return (0 - 9223372036854775807 - 1) }
  return w
}
saturating_mul := fn(a : i64, b : i64) -> i64 {
  w : i64 = unchecked { a * b }
  mut hi : i64 = a
  comptime if target.arch == Arch.x86_64 { x86_64.imulhiq(hi, b) }
  comptime if target.arch == Arch.aarch64 { aarch64.smulh(hi, a, b) }
  comptime if target.arch == Arch.riscv64 { riscv64.mulh(hi, a, b) }
  mut ovf : bool = false
  if w >= 0 and hi != 0 { ovf = true }
  if w < 0 and hi != (0 - 1) { ovf = true }
  if ovf {
    if a < 0 {
      if b < 0 { return 9223372036854775807 }
      return (0 - 9223372036854775807 - 1)
    }
    if b < 0 { return (0 - 9223372036854775807 - 1) }
    return 9223372036854775807
  }
  return w
}
