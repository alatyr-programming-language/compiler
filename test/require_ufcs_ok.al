## §8.1 — `T.require(pred)` is equivalent to `@require(pred) T` for a scalar type.
is_nonzero := fn(v : u32) -> bool { return v != 0 }
NonZero := u32.require(is_nonzero)

main := fn() -> u64 {
  x := NonZero(7)
  return 42
}
