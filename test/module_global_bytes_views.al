## Types §7 — `str` and `bytes(str)` are the same two-word {ptr, len} view. Exercise all three
## module-constant positions through the shared pair lowering: immediate, bound, and initializer.
ALPHA := "()*+"
ALPHA_BYTES := bytes("()*+")

main := fn() -> u64 {
  mut i : usize = 2
  immediate := u64(bytes(ALPHA)[i])
  bound := bytes(ALPHA)
  initialized := u64(ALPHA_BYTES[i])
  return immediate + u64(bound[i]) + initialized - 84
}
