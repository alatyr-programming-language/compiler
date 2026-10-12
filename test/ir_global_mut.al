## IR slice 3b (`docs/ir-slice-3.md` §6): a mutable module scalar is a place — read with a `load` at its
## type, written as its WHOLE one-word cell (the value widened to 64 bits first), so a legacy reader
## sees the canonical value at any width, including a negative `i32`. `lstep`/`lread` hold a float
## local, which keeps them on the legacy emitter until slice 8. Answers 42 everywhere.
mut G : u64 = 1
mut H : i32 = -5
step := fn(x : u64) { G = G + x }
lstep := fn() {
  f : f64 = 1.0
  G = G * 2
}
neg := fn() -> i32 {
  H = H - 1
  H
}
lread := fn() -> i64 {
  f : f64 = 1.0
  i64(H)
}
main := fn() -> u64 {
  step(4)
  lstep()
  step(11)
  h := neg()
  if G == 21 and h == 0 - 6 and lread() == 0 - 6 { return 42 }
  1
}
