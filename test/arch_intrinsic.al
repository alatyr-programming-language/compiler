## e2e — x86_64 instruction INTRINSICS (A-7 / §80.3). num.al's `@inline` scalar operators
## name arch instructions (`x86_64.addq`/`imulq`/`subq`/`remq`/`idivq`/`addsd`/…) inside a
## `comptime if target.arch == Arch.x86_64` (folded TRUE on this x86_64 target). The lean lower
## emits each as a REAL instruction that mutates its first arg (a scalar local lvalue) in place.
## Exercises integer + float intrinsics, both bare and comptime-if-wrapped; the composed result
## is 42. Guards the intrinsic-lowering path (additive: `src/` names no intrinsic, fixpoint-free).
add3 := fn(x : u64, y : u64) -> u64 {
  mut out : u64 = x
  comptime if target.arch == Arch.x86_64 { x86_64.addq(out, y) }
  return out
}
main := fn() -> u64 {
  mut a : u64 = 5
  x86_64.imulq(a, 8)         ## 40
  a = add3(a, 4)             ## 44 (comptime-if-wrapped addq, num.al's operator shape)
  x86_64.subq(a, 2)          ## 42
  mut r : u64 = 85
  x86_64.remq(r, 43)         ## 85 % 43 = 42
  mut d : i64 = 0 - 126
  x86_64.idivq(d, 3)         ## -42
  mut f : f64 = 40.0
  comptime if target.arch == Arch.x86_64 { x86_64.addsd(f, 2.0) }   ## 42.0
  return a + (r - 42) + unchecked bitcast(u64, d + 42) + (u64(f) - 42)
}
