## §8.1 multi-token underlying: a validity contract over a pointer type. The predicate receives the
## pointer value through the ordinary one-word pointer ABI and the explicit constructor preserves it.
is_nonnull := fn(p : ptr(u64)) -> bool { return bitcast(usize, p) != 0 }
NonNull := @require(is_nonnull) ptr(u64)

main := fn() -> u64 {
  mut x : u64 = 42
  p := ptr(x)
  q := NonNull(p)
  return deref(q)
}
