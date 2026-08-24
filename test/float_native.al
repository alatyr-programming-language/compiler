## Cross-backend FLOAT value model: float literal + arithmetic + float->int cast (no ABI).
## 1.5 + 2.5 = 4.0 -> u64 = 4. aarch64 now does local+global floats (ABI still traps).
main := fn() -> u64 {
  x := 1.5
  y := 2.5
  z := x + y
  return u64(z)
}
