## Companion to checked_index_bind_ovf (I11 / CG-6): an in-range `x := xs[i]` then `x + <literal>`
## returns the correct value under the SAME narrow-element classification — 40 + 2 = 42 fits `u8`, so
## no trap. Confirms the index-read-binding element-type recovery adds the width check WITHOUT breaking
## an ordinary in-range narrow add. x86-only (narrow arith is x86-only today).
main := fn() -> u64 {
  xs : [u8; 4] = [40, 100, 1, 2]
  i : u64 = 0
  x := xs[i]
  y := x + 2
  return u64(y)
}
