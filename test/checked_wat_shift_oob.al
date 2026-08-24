## Checked-mode over-width shift trap for WASM (I11 / OP-6): a native-width `u64` shift count
## `n >= 64` must trap. Without the WAT guard, WASM masks the count mod 64 and returns 1.
main := fn() -> u64 {
  x : u64 = 1
  return shl(x, 64)
}
