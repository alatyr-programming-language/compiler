## §8.1 multi-token underlying: a violating pointer validity contract must trap at construction.
is_nonnull := fn(p : ptr(u64)) -> bool { return bitcast(usize, p) != 0 }
NonNull := @require(is_nonnull) ptr(u64)

main := fn() -> u64 {
  p := unchecked bitcast(ptr(u64), 0)
  q := NonNull(p)
  return bitcast(u64, q)
}
