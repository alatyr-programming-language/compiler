## `min` / `max` — the v1 `Ord` consumers (Stdlib §2.6).
## Base tier (freestanding, no allocation). Generic over any ordered `T` — a
## type providing `<` (the `lt` operator-function); for the kernel scalars `<`
## is the builtin comparison. A **tie returns the first argument**.
##
## `T : type` is a comptime type parameter (comptime by nature; Functions §3),
## so a caller writes `min(a, b)` and the type is inferred from the arguments.
pub min := fn(T : type, a : T, b : T) -> T {
  if b < a { return b }
  return a
}

pub max := fn(T : type, a : T, b : T) -> T {
  if a < b { return b }
  return a
}

## `clamp` — confine `x` to `[lo, hi]` (Stdlib §2.6). Requires `lo <= hi`: a
## violation is a **checked precondition** that traps (a defined failure, I11).
pub clamp := fn(T : type, x : T, lo : T, hi : T) -> T {
  if hi < lo { panic("clamp: lo > hi") }
  if x < lo { return lo }
  if hi < x { return hi }
  return x
}

## Native scalar comparison operators (§4.3a, [[compiler-is-bitblocks-and-instructions-vision]]).
## The scalar ordering operators (`<`/`<=`/`>`/`>=`) route through `lt`, and the
## equality operators (`==`/`!=`) through `eq` — exactly the same mechanism the
## structural derive uses for a `Struct`/`Enum`, so a comparison is a library call
## that inlines to one flags→`bool` instruction. **Signedness IS which instruction
## the body selects**: `setb` (unsigned "below") vs `setl` (signed "less"). Lowered
## to `cmp`+`setcc`+`movzbq`. x86_64 first (the priority arch); other arches keep
## the built-in comparison until their fused `cmp`+`cset` lands (ROADMAP §4.3a).
@inline lt := fn(a : u64, b : u64) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setb(out, a, b) }
  return out
}

@inline lt := fn(a : i64, b : i64) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setl(out, a, b) }
  return out
}

@inline eq := fn(a : u64, b : u64) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.sete(out, a, b) }
  return out
}

@inline eq := fn(a : i64, b : i64) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.sete(out, a, b) }
  return out
}

## `u32`/`i32` comparisons — the narrower-width counterpart (§4). A 32-bit value
## is held sign/zero-extended in its 64-bit register home, so the same
## `cmp`(`q`)+`setcc` shape is correct: `setb`/`setl` select unsigned vs signed.
## Scalar comparison routing is x86_64-gated (`routes_comparison`), so — like the
## 64-bit ones — only the x86_64 branch is needed; other arches keep the built-in
## comparison.
@inline lt := fn(a : u32, b : u32) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setb(out, a, b) }
  return out
}

@inline lt := fn(a : i32, b : i32) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setl(out, a, b) }
  return out
}

@inline eq := fn(a : u32, b : u32) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.sete(out, a, b) }
  return out
}

@inline eq := fn(a : i32, b : i32) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.sete(out, a, b) }
  return out
}

## `u8`/`i8`/`u16`/`i16` comparisons — same shape (a narrow value is held
## sign/zero-extended in its register, so `cmpq`+`setcc` is correct); `setb`
## unsigned vs `setl` signed. x86_64-gated like the wider ones.
@inline lt := fn(a : u8, b : u8) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setb(out, a, b) }
  return out
}
@inline eq := fn(a : u8, b : u8) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.sete(out, a, b) }
  return out
}
@inline lt := fn(a : i8, b : i8) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setl(out, a, b) }
  return out
}
@inline eq := fn(a : i8, b : i8) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.sete(out, a, b) }
  return out
}
@inline lt := fn(a : u16, b : u16) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setb(out, a, b) }
  return out
}
@inline eq := fn(a : u16, b : u16) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.sete(out, a, b) }
  return out
}
@inline lt := fn(a : i16, b : i16) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.setl(out, a, b) }
  return out
}
@inline eq := fn(a : i16, b : i16) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.sete(out, a, b) }
  return out
}

## `f32`/`f64` comparisons — the **float** native operators (§4.3a). The two
## primitives `lt` (ordered `<`) and `eq` (ordered `==`) lower to a `ucomi*` +
## NaN-aware setcc (`fltsd`/`feqsd` = double, `fltss`/`feqss` = single — synthetic
## destination-first intrinsics, Assembly §80 §4.1). NaN comparisons are
## **unordered → false** (IEEE-754, Concurrency §7.5): `lt`/`eq` yield `false` for
## a NaN operand, so `>`/`==` are `false` and `!=` (`not eq`) is `true`. The
## non-strict `<=`/`>=` MUST derive as `lt OR eq` (NOT the total-order shortcut
## `not lt(swapped)`, which would be `true` for NaN) — the compiler routes them so
## (§4.3a float branch). x86_64-gated like the integer comparisons.
@inline lt := fn(a : f64, b : f64) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.fltsd(out, a, b) }
  return out
}
@inline eq := fn(a : f64, b : f64) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.feqsd(out, a, b) }
  return out
}
@inline lt := fn(a : f32, b : f32) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.fltss(out, a, b) }
  return out
}
@inline eq := fn(a : f32, b : f32) -> bool {
  mut out : bool = false
  comptime if target.arch == Arch.x86_64 { x86_64.feqss(out, a, b) }
  return out
}
