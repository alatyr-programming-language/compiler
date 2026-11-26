## #1718 — beside a program-declared `bitcast`, a call written in the reinterpret's shape is the
## prelude's reinterpret. Declarations §6.1 joins the declaration to the prelude's overload set: the
## program's `(u64, u64)` does not accept a type as its first argument, so the call falls back to the
## prelude's generic `bitcast(T, v)` (Stdlib appendix §2.6), and the bits of `x` read as `u64` are 42.
## NON-VACUOUS: with the declaration forcing every `bitcast(` to an ordinary call (the first cut of
## this fix), the program was refused; on the parent da8f96af it built (the reinterpret, by spelling).
bitcast := fn(a : u64, b : u64) -> u64 { a }
main := fn() -> u64 {
  x : i64 = 42
  y := bitcast(u64, x)
  y
}
## expect: run 42
