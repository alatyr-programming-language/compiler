## e2e — Types §9.1 at 32 bits: `u32` holds [0, 4294967295]. Located at the binding (line 3).
main := fn() -> i64 {
  x : u32 = 5000000000
  return i64(x)
}
