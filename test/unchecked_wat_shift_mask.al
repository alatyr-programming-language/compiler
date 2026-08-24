## Inside `unchecked`, the WAT over-width shift guard is dropped. WASM masks a 64-bit shift count
## modulo 64, so `shl(1, 64)` leaves 1.
main := fn() -> u64 {
  x : u64 = 1
  y := unchecked { shl(x, 64) }
  if y == 1 { return 42 }
  return y
}
